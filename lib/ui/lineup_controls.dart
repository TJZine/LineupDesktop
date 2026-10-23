import 'package:flutter/material.dart';

import '../plex/plex_models.dart';
import 'app_theme.dart';
import 'lineup_focus.dart';

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
        style: LineupTypography.fieldLabelFor(LineupTheme.of(context))
            .copyWith(color: LineupTheme.of(context).secondaryText),
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
                foregroundColor: WidgetStateProperty.resolveWith(
                  (states) =>
                      roles.focusTreatment == LineupFocusTreatment.fill &&
                          states.contains(WidgetState.focused)
                      ? roles.onFocus
                      : selected
                      ? roles.primaryText
                      : roles.secondaryText,
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
        style: LineupTheme.segmentedStyle(roles, focusVisible: visible)
            .copyWith(
              minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 16),
              ),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
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
      plexConnectionHasWarning(connection);
  static String description(PlexConnection? connection) =>
      plexConnectionDescription(connection);

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
    this.locked = false,
    super.key,
  });
  final String name;
  final String identity;
  final ImageProvider? photo;
  final double size;
  final bool locked;
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
    final avatar = ClipOval(
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
                      fontSize: size * .32,
                      color: const Color(0xFF20150F),
                    ),
                  ),
                ),
              ),
      ),
    );
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: avatar),
          if (locked)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: size * .3,
                height: size * .3,
                decoration: BoxDecoration(
                  color: LineupTheme.of(context).elevatedSurface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: LineupTheme.of(context).defaultBorder,
                  ),
                ),
                child: Semantics(
                  label: 'Profile lock',
                  child: Icon(
                    Icons.lock,
                    size: size * .17,
                    color: LineupTheme.of(context).primaryText,
                  ),
                ),
              ),
            ),
        ],
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
  icon: Icon(icon, semanticLabel: tooltip),
);

/// Reuses the child's real focus/traversal and adds selection plus a distinct ring.
class LineupRowSurface extends StatefulWidget {
  const LineupRowSurface({
    required this.selected,
    required this.child,
    this.focused = false,
    this.scaleOnFocus = false,
    super.key,
  });
  final bool selected;
  final bool focused;
  final bool scaleOnFocus;
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
    final focusFill =
        focused && roles.focusTreatment == LineupFocusTreatment.fill;
    final focusRing =
        focused && roles.focusTreatment == LineupFocusTreatment.ring;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final scale = widget.scaleOnFocus && focusFill && !reduceMotion
        ? 1.06
        : 1.0;
    final material = Material(
      type: MaterialType.transparency,
      child: widget.child,
    );
    final content = roles.focusTreatment == LineupFocusTreatment.fill
        ? LineupFocusInk(
            focused: focusFill,
            child: LineupFocusFrame(focused: focusFill, child: material),
          )
        : material;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (value) => setState(() => _focused = value),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: widget.scaleOnFocus
            ? AnimatedScale(
                scale: scale,
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                child: _rowSurfaceContainer(
                  roles: roles,
                  focusFill: focusFill,
                  focusRing: focusRing,
                  selected: widget.selected,
                  hovered: _hovered,
                  child: content,
                ),
              )
            : _rowSurfaceContainer(
                roles: roles,
                focusFill: focusFill,
                focusRing: focusRing,
                selected: widget.selected,
                hovered: _hovered,
                child: content,
              ),
      ),
    );
  }
}

Widget _rowSurfaceContainer({
  required LineupThemeRoles roles,
  required bool focusFill,
  required bool focusRing,
  required bool selected,
  required bool hovered,
  required Widget child,
}) => Container(
  decoration: BoxDecoration(
    color: focusFill
        ? roles.focusedSurface
        : selected
        ? roles.selectedSurface
        : hovered
        ? roles.primaryText.withValues(alpha: .08)
        : Colors.transparent,
    border: Border(
      left: BorderSide(
        color: selected ? roles.progressFill : Colors.transparent,
        width: 3,
      ),
    ),
  ),
  foregroundDecoration: BoxDecoration(
    border: Border.all(
      color: focusRing ? roles.focusBorder : Colors.transparent,
      width: focusRing ? roles.focusBorderWidth : 0,
    ),
  ),
  child: child,
);

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
  List<Widget>? selectedItemChildren,
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
      selectedItemChildren ??
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
    final focusFill =
        visible && roles.focusTreatment == LineupFocusTreatment.fill;
    final focusRing =
        visible && roles.focusTreatment == LineupFocusTreatment.ring;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (value) => setState(() => _focused = value),
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        constraints: BoxConstraints(minHeight: widget.compact ? 44 : 56),
        padding: EdgeInsets.symmetric(horizontal: widget.compact ? 14 : 18),
        decoration: BoxDecoration(
          color: focusFill ? roles.focusedSurface : roles.onFocus,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: focusRing
                ? roles.focusBorder
                : widget.enabled
                ? roles.defaultBorder
                : roles.defaultBorder.withValues(alpha: .5),
            width: focusRing ? roles.focusBorderWidth : 1,
          ),
        ),
        child: LineupFocusFrame(
          focused: focusFill,
          child: LineupFocusInk(
            focused: focusFill,
            child: Material(
              type: MaterialType.transparency,
              child: Builder(builder: (context) => widget.child),
            ),
          ),
        ),
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
      child: Builder(
        builder: (context) {
          final roles = LineupTheme.of(context);
          return InkWell(
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
                          ? roles.mutedText
                          : roles.primaryText,
                    ),
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down, size: 20),
              ],
            ),
          );
        },
      ),
    ),
  );
}

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
