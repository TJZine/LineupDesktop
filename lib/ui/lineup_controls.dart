import 'package:flutter/material.dart';

import '../plex/plex_models.dart';
import 'app_theme.dart';
import 'lineup_focus.dart';

/// Shared control sizing; color and state policy remain owned by the theme.
class LineupCompactControls extends StatelessWidget {
  const LineupCompactControls({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = LineupTheme.of(context);
    ButtonStyle style(LineupButtonTier tier) => LineupTheme.buttonStyle(
      roles,
      tier,
      compact: true,
      focusVisible: LineupFocusScope.visible(context),
    );
    return Theme(
      data: theme.copyWith(
        filledButtonTheme: FilledButtonThemeData(
          style: style(LineupButtonTier.primary),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: style(LineupButtonTier.secondary),
        ),
        textButtonTheme: TextButtonThemeData(
          style: style(LineupButtonTier.text),
        ),
        inputDecorationTheme: LineupTheme.fieldDecoration(
          roles,
          compact: true,
          focusVisible: LineupFocusScope.visible(context),
        ),
      ),
      child: child,
    );
  }
}

class LineupField extends StatelessWidget {
  const LineupField({required this.label, required this.child, super.key});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: LineupTypography.fieldLabel.copyWith(
          color: LineupTheme.of(context).secondaryText,
        ),
      ),
      const SizedBox(height: 8),
      child,
    ],
  );
}

/// Square selection is independent of keyboard focus and hover.
class LineupNavigationRow extends StatelessWidget {
  const LineupNavigationRow({
    required this.selected,
    required this.onPressed,
    required this.child,
    this.focusNode,
    this.autofocus = false,
    super.key,
  });
  final bool selected;
  final VoidCallback? onPressed;
  final Widget child;
  final FocusNode? focusNode;
  final bool autofocus;
  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    return Semantics(
      selected: selected,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? roles.selectedSurface : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: selected ? roles.progressFill : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: TextButton(
          focusNode: focusNode,
          autofocus: autofocus,
          onPressed: onPressed,
          style:
              LineupTheme.buttonStyle(
                roles,
                LineupButtonTier.text,
                focusVisible: LineupFocusScope.visible(context),
              ).copyWith(
                shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
                alignment: Alignment.centerLeft,
                foregroundColor: WidgetStatePropertyAll(
                  selected ? roles.primaryText : roles.secondaryText,
                ),
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                textStyle: const WidgetStatePropertyAll(
                  LineupTypography.control,
                ),
              ),
          child: child,
        ),
      ),
    );
  }
}

class LineupSegmentedControl<T> extends StatelessWidget {
  const LineupSegmentedControl({
    required this.segments,
    required this.selected,
    required this.onSelectionChanged,
    this.expanded = false,
    this.showSelectedIcon = false,
    this.direction = Axis.horizontal,
    this.multiSelectionEnabled = false,
    this.emptySelectionAllowed = false,
    super.key,
  });
  final List<ButtonSegment<T>> segments;
  final Set<T> selected;
  final ValueChanged<Set<T>>? onSelectionChanged;
  final bool expanded;
  final bool showSelectedIcon;
  final Axis direction;
  final bool multiSelectionEnabled;
  final bool emptySelectionAllowed;
  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final visible = LineupFocusScope.visible(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        border: Border.all(color: roles.defaultBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SegmentedButton<T>(
        segments: segments,
        selected: selected,
        direction: direction,
        multiSelectionEnabled: multiSelectionEnabled,
        emptySelectionAllowed: emptySelectionAllowed,
        showSelectedIcon: showSelectedIcon,
        onSelectionChanged: onSelectionChanged,
        expandedInsets: expanded && direction == Axis.horizontal
            ? EdgeInsets.zero
            : null,
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          side: WidgetStateProperty.resolveWith(
            (states) => visible && states.contains(WidgetState.focused)
                ? BorderSide(
                    color: roles.focusBorder,
                    width: roles.focusBorderWidth,
                  )
                : BorderSide.none,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? roles.selectedSurface
                : states.contains(WidgetState.hovered)
                ? roles.primaryText.withValues(alpha: .08)
                : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? roles.mutedText
                : states.contains(WidgetState.selected)
                ? roles.primaryText
                : roles.secondaryText,
          ),
          textStyle: WidgetStateProperty.resolveWith(
            (states) => LineupTypography.control.copyWith(
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w600
                  : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class LineupConnectionStatus extends StatelessWidget {
  const LineupConnectionStatus({required this.connection, super.key});
  final PlexConnection? connection;
  static bool hasWarning(PlexConnection? connection) =>
      connection?.latency != null &&
      (connection!.relay || connection.latency!.inMilliseconds >= 500);
  static String description(PlexConnection? connection) {
    if (connection?.latency == null) return 'Not measured yet';
    final measured = connection!;
    return [
      plexConnectionKindLabel(plexConnectionKind(measured)),
      if (measured.relay) 'Limited',
      if (measured.latency!.inMilliseconds >= 500) 'Very slow',
      '${measured.latency!.inMilliseconds} ms',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasWarning(connection)) ...[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: roles.progressFill,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            description(connection),
            style: LineupTypography.body.copyWith(color: roles.secondaryText),
          ),
        ),
      ],
    );
  }
}

class LineupProfileAvatar extends StatelessWidget {
  const LineupProfileAvatar({
    required this.name,
    required this.identity,
    this.photo,
    this.size = 64,
    super.key,
  });
  final String name;
  final String identity;
  final ImageProvider? photo;
  final double size;
  static const _tones = [
    Color(0xFFB98960),
    Color(0xFFC5A275),
    Color(0xFF9E735A),
    Color(0xFFB47B68),
    Color(0xFFA98D65),
    Color(0xFFC39B85),
  ];
  @override
  Widget build(BuildContext context) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    final initials = words.isEmpty
        ? '?'
        : words
              .take(2)
              .map((word) => word.characters.first.toUpperCase())
              .join();
    final hash = identity.codeUnits.fold(
      0,
      (value, unit) => (value * 31 + unit) & 0x7fffffff,
    );
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: ColoredBox(
          color: _tones[hash % _tones.length],
          child: photo == null
              ? Center(
                  child: Text(
                    initials,
                    style: LineupTypography.control.copyWith(
                      fontSize: size * .32,
                      color: const Color(0xFF20150F),
                    ),
                  ),
                )
              : Image(
                  image: photo!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, error, stack) => Center(
                    child: Text(
                      initials,
                      style: LineupTypography.control.copyWith(
                        color: const Color(0xFF20150F),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

IconButton lineupArrowButton({
  Key? key,
  required IconData icon,
  required VoidCallback? onPressed,
  String? tooltip,
  FocusNode? focusNode,
}) => IconButton(
  key: key,
  onPressed: onPressed,
  tooltip: tooltip,
  focusNode: focusNode,
  icon: Icon(icon),
);

/// Reuses the child's real focus/traversal and adds selection plus a distinct ring.
class LineupRowSurface extends StatefulWidget {
  const LineupRowSurface({
    required this.selected,
    required this.child,
    this.focused = false,
    super.key,
  });
  final bool selected;
  final bool focused;
  final Widget child;
  @override
  State<LineupRowSurface> createState() => _LineupRowSurfaceState();
}

class _LineupRowSurfaceState extends State<LineupRowSurface> {
  bool _focused = false;
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final focused = LineupFocusScope.visible(
      context,
      _focused || widget.focused,
    );
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (value) => setState(() => _focused = value),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Container(
          decoration: BoxDecoration(
            color: widget.selected
                ? roles.selectedSurface
                : _hovered
                ? roles.primaryText.withValues(alpha: .08)
                : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: widget.selected
                    ? roles.progressFill
                    : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          foregroundDecoration: BoxDecoration(
            border: Border.all(
              color: focused ? roles.focusBorder : Colors.transparent,
              width: focused ? roles.focusBorderWidth : 0,
            ),
          ),
          child: Material(type: MaterialType.transparency, child: widget.child),
        ),
      ),
    );
  }
}

class LineupTab extends StatelessWidget {
  const LineupTab({
    required this.label,
    required this.count,
    required this.selected,
    required this.onPressed,
    super.key,
  });
  final String label;
  final int count;
  final bool selected;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    return Semantics(
      selected: selected,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? roles.progressFill : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: LineupCompactControls(
          child: TextButton(
            onPressed: onPressed,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: label,
                    style: LineupTypography.control.copyWith(
                      color: selected ? roles.primaryText : roles.secondaryText,
                    ),
                  ),
                  TextSpan(
                    text: ' · $count',
                    style: LineupTypography.control.copyWith(
                      color: roles.mutedText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LineupDropdownMenuRow extends StatelessWidget {
  const LineupDropdownMenuRow({
    required this.selected,
    required this.child,
    super.key,
  });
  final bool selected;
  final Widget child;
  @override
  Widget build(BuildContext context) => LineupRowSurface(
    selected: selected,
    // The popup owns the interactive focus node above its item content.
    focused: Focus.maybeOf(context)?.hasFocus ?? false,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: child,
    ),
  );
}

List<DropdownMenuItem<T>> lineupMenuItems<T>(
  List<DropdownMenuItem<T>>? items,
  T? selected,
) => [
  for (final item in items ?? <DropdownMenuItem<T>>[])
    DropdownMenuItem<T>(
      value: item.value,
      enabled: item.enabled,
      onTap: item.onTap,
      child: LineupDropdownMenuRow(
        selected: item.value == selected,
        child: item.child,
      ),
    ),
];

DropdownButtonFormField<T> lineupDropdownField<T>({
  required BuildContext context,
  required List<DropdownMenuItem<T>>? items,
  required ValueChanged<T?>? onChanged,
  Key? key,
  T? initialValue,
  bool isExpanded = true,
  double iconSize = 20,
  double? itemHeight = kMinInteractiveDimension,
  Widget? icon,
  TextStyle? style,
  InputDecoration decoration = const InputDecoration(),
  FormFieldValidator<T>? validator,
  FocusNode? focusNode,
  bool autofocus = false,
}) => DropdownButtonFormField<T>(
  key: key,
  initialValue: initialValue,
  onChanged: onChanged,
  items: lineupMenuItems(items, initialValue),
  selectedItemBuilder: (_) =>
      (items ?? <DropdownMenuItem<T>>[]).map((item) => item.child).toList(),
  dropdownColor: LineupTheme.of(context).elevatedSurface,
  borderRadius: BorderRadius.circular(8),
  isExpanded: isExpanded,
  iconSize: iconSize,
  itemHeight: itemHeight,
  icon: icon ?? const Icon(Icons.keyboard_arrow_down),
  style: style ?? LineupTypography.control,
  decoration: decoration,
  validator: validator,
  focusNode: focusNode,
  autofocus: autofocus,
);

/// Dropdown trigger uses the same inset field and keyboard ring as text inputs.
class LineupDropdownBox extends StatefulWidget {
  const LineupDropdownBox({
    required this.child,
    required this.enabled,
    this.compact = false,
    super.key,
  });
  final Widget child;
  final bool enabled;
  final bool compact;
  @override
  State<LineupDropdownBox> createState() => _LineupDropdownBoxState();
}

class _LineupDropdownBoxState extends State<LineupDropdownBox> {
  bool _focused = false;
  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final visible = LineupFocusScope.visible(context, _focused);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (value) => setState(() => _focused = value),
      child: Container(
        constraints: BoxConstraints(minHeight: widget.compact ? 44 : 56),
        padding: EdgeInsets.symmetric(horizontal: widget.compact ? 14 : 18),
        decoration: BoxDecoration(
          color: roles.onFocus,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: visible
                ? roles.focusBorder
                : widget.enabled
                ? roles.defaultBorder
                : roles.defaultBorder.withValues(alpha: .5),
            width: visible ? roles.focusBorderWidth : 1,
          ),
        ),
        child: Material(type: MaterialType.transparency, child: widget.child),
      ),
    );
  }
}

class LineupFieldButton extends StatelessWidget {
  const LineupFieldButton({
    required this.label,
    required this.value,
    required this.onPressed,
    this.focusNode,
    super.key,
  });
  final String label;
  final String value;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  @override
  Widget build(BuildContext context) => LineupField(
    label: label,
    child: LineupDropdownBox(
      enabled: onPressed != null,
      child: InkWell(
        focusNode: focusNode,
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: LineupTypography.control.copyWith(
                  color: onPressed == null
                      ? LineupTheme.of(context).mutedText
                      : LineupTheme.of(context).primaryText,
                ),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down, size: 20),
          ],
        ),
      ),
    ),
  );
}

/// Content links share the theme's compact target, amber tier and focus policy.
class LineupInlineLink extends StatelessWidget {
  const LineupInlineLink({
    required this.onPressed,
    required this.child,
    this.focusNode,
    this.autofocus = false,
    super.key,
  });
  final VoidCallback? onPressed;
  final Widget child;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    focusNode: focusNode,
    autofocus: autofocus,
    style: LineupTheme.buttonStyle(
      LineupTheme.of(context),
      LineupButtonTier.link,
      compact: true,
      focusVisible: LineupFocusScope.visible(context),
    ),
    child: child,
  );
}

class LineupDestructiveButton extends StatelessWidget {
  const LineupDestructiveButton({
    required this.onPressed,
    required this.child,
    super.key,
  });
  final VoidCallback? onPressed;
  final Widget child;
  @override
  Widget build(BuildContext context) => FilledButton(
    style: LineupTheme.buttonStyle(
      LineupTheme.of(context),
      LineupButtonTier.destructive,
      focusVisible: LineupFocusScope.visible(context),
    ),
    onPressed: onPressed,
    child: child,
  );
}
