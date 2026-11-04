import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:lineup_desktop/platform/device_profile.dart';

import 'app_theme.dart';
import 'lineup_canvas.dart';
import 'lineup_controls.dart';

/// UI-B's canvas-width threshold for the stacked management composition.
const handheldTableMinimum = 1100.0;

/// The gutter used by stacked management surfaces in canvas units.
const handheldGutter = 18.0;

/// The maximum width of a centered stacked management column in canvas units.
const handheldMaxContent = 840.0;

/// Returns whether the current management surface should use the UI-B stacked
/// composition.
///
/// Handheld-class windows always use the stacked composition. A Wide handheld
/// window switches when its canvas width, after the current text scale, is
/// below the approved 1100 cu threshold. Desktop and TV profiles never opt in.
bool handheldStacked(BuildContext context) {
  if (!DeviceProfile.of(context).isHandheld) return false;
  if (LineupCanvas.compositionOf(context) == LineupComposition.handheld) {
    return true;
  }
  final textScale = MediaQuery.textScalerOf(context).scale(1);
  return textScale > 0 &&
      MediaQuery.sizeOf(context).width / textScale < handheldTableMinimum;
}

/// A centered 840 cu column with the UI-B 18 cu side gutter.
///
/// [LineupContentWidth] has the same geometry as an opt-in for pages that
/// already own their outer content scaffold. This widget is useful for a
/// surface that owns its body layout directly.
class HandheldColumnWidth extends StatelessWidget {
  const HandheldColumnWidth({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: handheldGutter),
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: handheldMaxContent),
        child: SizedBox(width: double.infinity, child: child),
      ),
    ),
  );
}

double _minimumTouchExtent(BuildContext context, {double designExtent = 54}) {
  final required = LineupCanvas.minimumTouchExtentOf(context);
  // Keep the transformed layout at or above 48 dp even when the canvas
  // transform rounds a mathematically exact 48 to 47.99999999999999.
  return math.max(designExtent, required > 0 ? required + .001 : 0);
}

TextStyle _controlStyle(BuildContext context, {Color? color}) =>
    LineupTypography.control.copyWith(
      color: color ?? LineupTheme.of(context).primaryText,
    );

/// A page-bar title that only breaks between words.
class _HandheldWordText extends StatelessWidget {
  const _HandheldWordText(
    this.text, {
    required this.style,
    this.maxLines,
    this.fitOverwideWords = false,
    this.breakAfter,
  });

  final String text;
  final TextStyle style;
  final int? maxLines;
  final bool fitOverwideWords;
  final Pattern? breakAfter;

  double _width(
    BuildContext context,
    String value, {
    TextScaler? textScaler,
    TextStyle? textStyle,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: DefaultTextStyle.of(context).style.merge(textStyle ?? style),
      ),
      textDirection: Directionality.of(context),
      textScaler: textScaler ?? MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  TextStyle _styleForWord(BuildContext context, String word, double maxWidth) {
    final requested = MediaQuery.textScalerOf(context);
    if (!fitOverwideWords || style.fontSize == null) return style;
    if (_width(context, word, textScaler: requested) <= maxWidth ||
        _width(context, word, textScaler: TextScaler.noScaling) > maxWidth) {
      return style;
    }

    var floor = 0.0;
    var ceiling = 1.0;
    for (var step = 0; step < 16; step++) {
      final middle = (floor + ceiling) / 2;
      if (requested.scale(style.fontSize! * middle) >= style.fontSize!) {
        ceiling = middle;
      } else {
        floor = middle;
      }
    }
    var low = ceiling;
    var high = 1.0;
    for (var step = 0; step < 16; step++) {
      final middle = (low + high) / 2;
      final wordStyle = style.copyWith(fontSize: style.fontSize! * middle);
      if (_width(context, word, textScaler: requested, textStyle: wordStyle) <=
          maxWidth - 1) {
        low = middle;
      } else {
        high = middle;
      }
    }
    return style.copyWith(fontSize: style.fontSize! * low);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final words = text.trim().isEmpty
          ? const <String>[]
          : text.trim().split(RegExp(r'\s+'));
      final spans = <InlineSpan>[];
      for (var index = 0; index < words.length; index++) {
        if (index > 0) spans.add(TextSpan(text: ' ', style: style));
        final word = words[index];
        var start = 0;
        for (final match in breakAfter?.allMatches(word) ?? const <Match>[]) {
          if (match.end <= start || match.end == word.length) continue;
          final part = word.substring(start, match.end);
          spans.add(
            TextSpan(
              text: part,
              style: _styleForWord(context, part, constraints.maxWidth),
            ),
          );
          // Keep the separator visible with its preceding text.
          spans.add(const TextSpan(text: '\u200b'));
          start = match.end;
        }
        final part = word.substring(start);
        spans.add(
          TextSpan(
            text: part,
            style: _styleForWord(context, part, constraints.maxWidth),
          ),
        );
      }
      return Text.rich(
        TextSpan(style: style, children: spans),
        maxLines: maxLines,
        softWrap: true,
        overflow: maxLines == null
            ? TextOverflow.visible
            : TextOverflow.ellipsis,
      );
    },
  );
}

/// B1 page bar for stacked management surfaces.
class HandheldPageBar extends StatelessWidget {
  const HandheldPageBar({
    required this.title,
    this.onBack,
    this.backTooltip = 'Back',
    this.backIcon = Icons.arrow_back,
    this.actions = const [],
    this.leading,
    this.subtitle,
    this.tabRoot = false,
    this.titleBreakAfter,
    super.key,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final String backTooltip;
  final IconData backIcon;
  final List<Widget> actions;
  final Widget? leading;
  final bool tabRoot;

  /// Optional separators after which the visual title may wrap.
  final Pattern? titleBreakAfter;

  Widget _backButton(BuildContext context) {
    final extent = _minimumTouchExtent(context, designExtent: 56);
    return LineupTouchTarget(
      onPressed: onBack,
      child: IconButton(
        tooltip: backTooltip,
        onPressed: onBack,
        padding: EdgeInsets.zero,
        constraints: BoxConstraints(minWidth: extent, minHeight: extent),
        icon: Icon(backIcon, color: LineupTheme.of(context).primaryText),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final titleStyle = LineupTypography.title(
      tabRoot ? 30 : 26,
      90,
      height: 1.12,
    ).copyWith(color: roles.primaryText);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            onBack == null && leading == null && !tabRoot ? handheldGutter : 4,
            6,
            4,
            6,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (onBack != null) _backButton(context),
              if (tabRoot && leading == null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Image.asset(
                    'assets/branding/lineup-logo-mark.png',
                    width: 34,
                    height: 34,
                    excludeFromSemantics: true,
                  ),
                ),
              ?leading,
              Expanded(
                child: Semantics(
                  header: true,
                  label: subtitle == null ? title : '$title, $subtitle',
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      KeyedSubtree(
                        key: const ValueKey('handheld-page-bar-title'),
                        child: _HandheldWordText(
                          title,
                          style: titleStyle,
                          maxLines: 2,
                          fitOverwideWords: true,
                          breakAfter: titleBreakAfter,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: LineupTypography.small.copyWith(
                            color: roles.secondaryText,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                        ),
                    ],
                  ),
                ),
              ),
              for (final action in actions)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: _minimumTouchExtent(context, designExtent: 56),
                    minHeight: _minimumTouchExtent(context, designExtent: 56),
                  ),
                  child: action,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// B2's primary/secondary action layout. The primary action is last when the
/// labels need to stack, keeping it closest to the thumb.
class HandheldActionRow extends StatelessWidget {
  const HandheldActionRow({required this.primary, this.secondary, super.key});

  final Widget primary;
  final Widget? secondary;

  Widget _sized(BuildContext context, Widget child) => ConstrainedBox(
    constraints: BoxConstraints(
      minHeight: _minimumTouchExtent(context, designExtent: 54),
    ),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final secondary = this.secondary;
    if (secondary == null) return _sized(context, primary);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final narrow =
        textScale <= 0 || MediaQuery.sizeOf(context).width / textScale < 420;
    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sized(context, secondary),
          const SizedBox(height: 8),
          _sized(context, primary),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: _sized(context, secondary)),
        const SizedBox(width: 12),
        Expanded(child: _sized(context, primary)),
      ],
    );
  }
}

/// B2 sticky action bar used by the full-screen Setup flow.
class HandheldSetupActionBar extends StatelessWidget {
  const HandheldSetupActionBar({
    required this.primary,
    this.secondary,
    this.summary,
    this.consent,
    super.key,
  });

  final Widget primary;
  final Widget? secondary;
  final Widget? summary;
  final Widget? consent;

  @override
  Widget build(BuildContext context) {
    // MediaQuery insets are consumed by the Scaffold body. View.of is the
    // unconsumed source and keeps the bar hidden for the full IME lifetime.
    if (View.of(context).viewInsets.bottom > 0) return const SizedBox.shrink();
    final roles = LineupTheme.of(context);
    return DecoratedBox(
      key: const ValueKey('handheld-setup-action-bar'),
      decoration: BoxDecoration(
        color: roles.primarySurface,
        border: Border(top: BorderSide(color: roles.subtleBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            handheldGutter,
            12,
            handheldGutter,
            12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ?summary,
              if (summary != null && (consent != null || secondary != null))
                const SizedBox(height: 10),
              ?consent,
              if (consent != null) const SizedBox(height: 10),
              HandheldActionRow(primary: primary, secondary: secondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// B2 progress for the three Setup sections.
class HandheldStepProgress extends StatelessWidget {
  const HandheldStepProgress({
    required this.step,
    required this.label,
    this.total = 3,
    this.complete = false,
    super.key,
  });

  final int step;
  final int total;
  final String label;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final description = complete
        ? 'Setup complete'
        : 'Step $step of $total, $label';
    return Semantics(
      label: description,
      container: true,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            handheldGutter,
            0,
            handheldGutter,
            12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                complete ? 'Setup complete' : 'Step $step of $total · $label',
                style: LineupTypography.small.copyWith(
                  color: roles.secondaryText,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (var index = 1; index <= total; index++) ...[
                    if (index > 1) const SizedBox(width: 6),
                    Expanded(
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: complete || index <= step
                              ? roles.progressFill
                              : roles.progressTrack,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// B3 number block for a stacked channel row.
class HandheldNumberBlock extends StatelessWidget {
  const HandheldNumberBlock(this.number, {this.next, super.key});

  final int number;
  final int? next;

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final changes = next != null && next != number;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Semantics(
        label: changes
            ? 'Channel $number, will become $next'
            : 'Channel $number',
        container: true,
        child: ExcludeSemantics(
          child: SizedBox(
            width: 62,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$number',
                  style: LineupTypography.title(22, 90).copyWith(
                    color: roles.primaryText,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (changes)
                  Text(
                    '→ $next',
                    style: LineupTypography.small.copyWith(
                      color: roles.progressFill,
                      fontSize: 14,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A B3 badge with a swatch and a spoken label; color is never the only cue.
class HandheldBadge extends StatelessWidget {
  const HandheldBadge(this.label, {required this.color, super.key});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: LineupTypography.small.copyWith(
              color: roles.primaryText,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

enum _HandheldRowSlot { leading, number, text, trailing }

class _HandheldRowParentData extends ContainerBoxParentData<RenderBox> {
  _HandheldRowSlot? slot;
}

class _HandheldRowSlotChild extends ParentDataWidget<_HandheldRowParentData> {
  const _HandheldRowSlotChild({required this.slot, required super.child});

  final _HandheldRowSlot slot;

  @override
  void applyParentData(RenderObject renderObject) {
    final parentData = renderObject.parentData! as _HandheldRowParentData;
    if (parentData.slot == slot) return;
    parentData.slot = slot;
    renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => _HandheldRowLayout;
}

class _HandheldRowLayout extends MultiChildRenderObjectWidget {
  _HandheldRowLayout({
    required this.leading,
    required this.number,
    required this.text,
    required this.trailing,
    required this.name,
    required this.facts,
    required this.warning,
    required this.nameStyle,
    required this.factsStyle,
    required this.warningStyle,
    required this.textScaler,
    required this.textDirection,
    required this.touchExtent,
  }) : super(
         children: [
           if (leading != null)
             _HandheldRowSlotChild(
               slot: _HandheldRowSlot.leading,
               child: leading,
             ),
           _HandheldRowSlotChild(slot: _HandheldRowSlot.number, child: number),
           _HandheldRowSlotChild(slot: _HandheldRowSlot.text, child: text),
           if (trailing != null)
             _HandheldRowSlotChild(
               slot: _HandheldRowSlot.trailing,
               child: trailing,
             ),
         ],
       );

  final Widget? leading;
  final Widget number;
  final Widget text;
  final Widget? trailing;
  final String name;
  final String facts;
  final String? warning;
  final TextStyle nameStyle;
  final TextStyle factsStyle;
  final TextStyle warningStyle;
  final TextScaler textScaler;
  final TextDirection textDirection;
  final double touchExtent;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHandheldRow(
    name: name,
    facts: facts,
    warning: warning,
    nameStyle: nameStyle,
    factsStyle: factsStyle,
    warningStyle: warningStyle,
    textScaler: textScaler,
    textDirection: textDirection,
    touchExtent: touchExtent,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHandheldRow renderObject,
  ) {
    renderObject
      ..name = name
      ..facts = facts
      ..warning = warning
      ..nameStyle = nameStyle
      ..factsStyle = factsStyle
      ..warningStyle = warningStyle
      ..textScaler = textScaler
      ..textDirection = textDirection
      ..touchExtent = touchExtent
      ..markNeedsLayout();
  }
}

class _RenderHandheldRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _HandheldRowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _HandheldRowParentData> {
  _RenderHandheldRow({
    required this.name,
    required this.facts,
    required this.warning,
    required this.nameStyle,
    required this.factsStyle,
    required this.warningStyle,
    required this.textScaler,
    required this.textDirection,
    required this.touchExtent,
  });

  String name;
  String facts;
  String? warning;
  TextStyle nameStyle;
  TextStyle factsStyle;
  TextStyle warningStyle;
  TextScaler textScaler;
  TextDirection textDirection;
  double touchExtent;

  RenderBox? _childFor(_HandheldRowSlot slot) {
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final parentData = child.parentData! as _HandheldRowParentData;
      if (parentData.slot == slot) return child;
    }
    return null;
  }

  void _layoutChrome(RenderBox? child, double width, double maxHeight) {
    child?.layout(
      BoxConstraints.loose(Size(width, maxHeight)),
      parentUsesSize: true,
    );
  }

  bool _wordTooWide(String value, TextStyle style, double maxWidth) {
    if (value.trim().isEmpty) return false;
    for (final word in value.trim().split(RegExp(r'\s+'))) {
      final painter = TextPainter(
        text: TextSpan(text: word, style: style),
        textDirection: textDirection,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      final tooWide = painter.width > maxWidth;
      painter.dispose();
      if (tooWide) return true;
    }
    return false;
  }

  void _position(RenderBox child, double x, double y) {
    (child.parentData! as _HandheldRowParentData).offset = Offset(x, y);
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _HandheldRowParentData) {
      child.parentData = _HandheldRowParentData();
    }
  }

  @override
  void performLayout() {
    final width = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : constraints.minWidth;
    final maxHeight = constraints.maxHeight;
    final leading = _childFor(_HandheldRowSlot.leading);
    final number = _childFor(_HandheldRowSlot.number)!;
    final text = _childFor(_HandheldRowSlot.text)!;
    final trailing = _childFor(_HandheldRowSlot.trailing);
    _layoutChrome(leading, width, maxHeight);
    _layoutChrome(number, width, maxHeight);
    _layoutChrome(trailing, width, maxHeight);

    final leftPadding = leading == null ? handheldGutter : 4.0;
    final rightPadding = trailing == null ? handheldGutter : 2.0;
    final leadingWidth = leading?.size.width ?? 0;
    final trailingWidth = trailing?.size.width ?? 0;
    final double sideWidth = math
        .max(
          0,
          width -
              leftPadding -
              rightPadding -
              leadingWidth -
              number.size.width -
              trailingWidth,
        )
        .toDouble();
    final nameScale = textScaler.scale(18) / 18;
    final listStacked = nameScale <= 0 || width / nameScale < 280;
    final stacked =
        listStacked ||
        _wordTooWide(name, nameStyle, sideWidth) ||
        _wordTooWide(facts, factsStyle, sideWidth) ||
        (warning != null && _wordTooWide(warning!, warningStyle, sideWidth));

    final numberX = leftPadding + leadingWidth;
    final sideTextX = numberX + number.size.width;
    if (stacked) {
      final double topHeight = math
          .max(
            touchExtent,
            math.max(
              leading?.size.height ?? 0,
              math.max(number.size.height, trailing?.size.height ?? 0),
            ),
          )
          .toDouble();
      final double stackedTextWidth = math
          .max(0, width - numberX - handheldGutter)
          .toDouble();
      text.layout(
        BoxConstraints.tightFor(width: stackedTextWidth),
        parentUsesSize: true,
      );
      final top = 12.0;
      if (leading != null) {
        _position(
          leading,
          leftPadding,
          top + (topHeight - leading.size.height) / 2,
        );
      }
      _position(number, numberX, top + (topHeight - number.size.height) / 2);
      if (trailing != null) {
        _position(
          trailing,
          width - rightPadding - trailingWidth,
          top + (topHeight - trailing.size.height) / 2,
        );
      }
      _position(text, numberX, top + topHeight);
      size = constraints.constrain(
        Size(width, math.max(72, top + topHeight + text.size.height + 12)),
      );
      return;
    }

    text.layout(
      BoxConstraints.tightFor(width: sideWidth),
      parentUsesSize: true,
    );
    if (leading != null) _position(leading, leftPadding, 12);
    _position(number, numberX, 12);
    _position(text, sideTextX, 12);
    if (trailing != null) {
      _position(trailing, width - rightPadding - trailingWidth, 12);
    }
    final double contentHeight = math
        .max(
          text.size.height,
          math.max(
            leading?.size.height ?? 0,
            math.max(number.size.height, trailing?.size.height ?? 0),
          ),
        )
        .toDouble();
    size = constraints.constrain(Size(width, math.max(72, contentHeight + 24)));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// B3 stacked row. The row itself is the tap and long-press target.
class HandheldStackedRow extends StatelessWidget {
  const HandheldStackedRow({
    required this.number,
    required this.name,
    required this.facts,
    this.next,
    this.leading,
    this.badge,
    this.warning,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.removed = false,
    this.checked,
    super.key,
  });

  final int number;
  final int? next;
  final String name;
  final String facts;
  final Widget? leading;
  final Widget? badge;
  final String? warning;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool removed;
  final bool? checked;

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final inheritedStyle = DefaultTextStyle.of(context).style;
    final nameStyle = inheritedStyle.merge(
      _controlStyle(context).copyWith(
        color: removed ? roles.secondaryText : roles.primaryText,
        decoration: removed ? TextDecoration.lineThrough : null,
      ),
    );
    final factsStyle = inheritedStyle.merge(
      LineupTypography.small.copyWith(
        color: roles.secondaryText,
        fontSize: 15,
        height: 1.35,
      ),
    );
    final warningStyle = inheritedStyle.merge(
      LineupTypography.small.copyWith(
        color: Theme.of(context).colorScheme.error,
        fontSize: 15,
      ),
    );
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _HandheldWordText(name, style: nameStyle, fitOverwideWords: true),
        if (facts.isNotEmpty) ...[
          const SizedBox(height: 2),
          for (final line in facts.split('\n'))
            _HandheldWordText(line, style: factsStyle, fitOverwideWords: true),
        ],
        if (warning != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _HandheldWordText(
              warning!,
              style: warningStyle,
              fitOverwideWords: true,
            ),
          ),
        if (badge != null) ...[const SizedBox(height: 6), badge!],
      ],
    );
    final trailingWidget = trailing == null
        ? null
        : ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: _minimumTouchExtent(context, designExtent: 56),
              minHeight: _minimumTouchExtent(context, designExtent: 56),
            ),
            child: trailing,
          );
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 72),
      child: _HandheldRowLayout(
        leading: leading,
        number: HandheldNumberBlock(number, next: next),
        text: text,
        trailing: trailingWidget,
        name: name,
        facts: facts,
        warning: warning,
        nameStyle: nameStyle,
        factsStyle: factsStyle,
        warningStyle: warningStyle,
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: Directionality.of(context),
        touchExtent: _minimumTouchExtent(context, designExtent: 56),
      ),
    );
    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: roles.subtleBorder)),
      ),
      child: row,
    );
    if (onTap == null && onLongPress == null) return decorated;
    return Semantics(
      container: true,
      checked: checked,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          excludeFromSemantics: true,
          child: decorated,
        ),
      ),
    );
  }
}

/// B4's one-line, horizontally scrolling chip row.
class HandheldChipRow extends StatelessWidget {
  const HandheldChipRow({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: handheldGutter),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) const SizedBox(width: 8),
          children[index],
        ],
      ],
    ),
  );
}

/// B4 filter chip, including the approved section-position semantics.
class HandheldFilterChip extends StatelessWidget {
  const HandheldFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.count,
    this.swatch,
    this.section,
    this.sectionCount = 3,
    this.hideWhenZero = false,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback? onSelected;
  final int? count;
  final Color? swatch;
  final int? section;
  final int sectionCount;
  final bool hideWhenZero;

  @override
  Widget build(BuildContext context) {
    if (hideWhenZero && count == 0) return const SizedBox.shrink();
    final roles = LineupTheme.of(context);
    final text = count == null ? label : '$label ($count)';
    final sectionText = section == null
        ? null
        : 'Section $section of $sectionCount';
    final semanticsLabel = sectionText == null ? text : '$text, $sectionText';
    final extent = _minimumTouchExtent(context, designExtent: 54);
    return Semantics(
      label: semanticsLabel,
      selected: selected,
      button: true,
      onTap: onSelected,
      excludeSemantics: true,
      child: Material(
        color: selected ? roles.selectedSurface : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? roles.selectedSurface : roles.defaultBorder,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onSelected,
          excludeFromSemantics: true,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: extent,
              minWidth: math.max(56, extent),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (swatch != null) ...[
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: swatch,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    text,
                    style: LineupTypography.control.copyWith(
                      color: selected ? roles.primaryText : roles.secondaryText,
                      fontSize: 16,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                    softWrap: false,
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

/// An option in a B5 choice sheet.
class HandheldChoice<T> {
  const HandheldChoice({
    required this.value,
    required this.label,
    this.detail,
    this.destructive = false,
  });

  final T value;
  final String label;
  final String? detail;
  final bool destructive;
}

/// Opens a B5 bottom choice sheet and resolves with the tapped option.
Future<T?> showHandheldChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<HandheldChoice<T>> choices,
  T? selected,
  bool showSelection = true,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: false,
  backgroundColor: LineupTheme.of(context).elevatedSurface,
  constraints: BoxConstraints(
    maxHeight: MediaQuery.sizeOf(context).height * .9,
  ),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
  ),
  builder: (context) => HandheldChoiceSheet<T>(
    title: title,
    choices: choices,
    selected: selected,
    showSelection: showSelection,
  ),
);

class HandheldChoiceSheet<T> extends StatelessWidget {
  const HandheldChoiceSheet({
    required this.title,
    required this.choices,
    this.selected,
    this.showSelection = true,
    super.key,
  });

  final String title;
  final List<HandheldChoice<T>> choices;
  final T? selected;
  final bool showSelection;

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        Semantics(
          header: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              handheldGutter + 4,
              0,
              handheldGutter,
              8,
            ),
            child: Column(
              children: [
                SizedBox(
                  height: 43,
                  child: Center(
                    child: SizedBox(
                      width: 36,
                      height: 4,
                      child: DecoratedBox(
                        decoration: ShapeDecoration(
                          color: roles.mutedText,
                          shape: const StadiumBorder(),
                        ),
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.3,
                    child: _HandheldWordText(
                      title,
                      style: LineupTypography.title(
                        24,
                        90,
                      ).copyWith(color: roles.primaryText),
                      maxLines: 2,
                      fitOverwideWords: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        for (final choice in choices)
          _HandheldChoiceRow<T>(
            choice: choice,
            selected: choice.value == selected,
            showSelection: showSelection,
          ),
      ],
    );
  }
}

class _HandheldChoiceRow<T> extends StatelessWidget {
  const _HandheldChoiceRow({
    required this.choice,
    required this.selected,
    required this.showSelection,
  });

  final HandheldChoice<T> choice;
  final bool selected;
  final bool showSelection;

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final color = choice.destructive
        ? Theme.of(context).colorScheme.error
        : roles.primaryText;
    final label = choice.detail == null
        ? choice.label
        : '${choice.label}, ${choice.detail}';
    final extent = _minimumTouchExtent(context, designExtent: 64);
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      onTap: () => Navigator.of(context).pop(choice.value),
      excludeSemantics: true,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(choice.value),
        excludeFromSemantics: true,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: extent),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: handheldGutter + 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _HandheldWordText(
                        choice.label,
                        style: _controlStyle(context, color: color),
                      ),
                      if (choice.detail != null)
                        _HandheldWordText(
                          choice.detail!,
                          style: LineupTypography.small.copyWith(
                            color: roles.secondaryText,
                            fontSize: 15,
                          ),
                        ),
                    ],
                  ),
                ),
                if (showSelection && selected)
                  Icon(Icons.check, color: roles.progressFill),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// B5 select field. The current value stays on one line and opens a choice
/// sheet on activation.
class HandheldSelectField<T> extends StatelessWidget {
  const HandheldSelectField({
    required this.label,
    required this.value,
    required this.choices,
    required this.onChanged,
    super.key,
  });

  final String label;
  final T value;
  final List<HandheldChoice<T>> choices;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final current = choices.cast<HandheldChoice<T>?>().firstWhere(
      (choice) => choice?.value == value,
      orElse: () => null,
    );
    final extent = _minimumTouchExtent(context, designExtent: 54);
    return Semantics(
      label: '$label, ${current?.label ?? ''}',
      button: true,
      excludeSemantics: true,
      onTap: onChanged == null
          ? null
          : () async {
              final picked = await showHandheldChoiceSheet<T>(
                context,
                title: label,
                choices: choices,
                selected: value,
              );
              if (picked != null) onChanged!(picked);
            },
      child: Material(
        color: roles.primarySurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: roles.defaultBorder),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onChanged == null
              ? null
              : () async {
                  final picked = await showHandheldChoiceSheet<T>(
                    context,
                    title: label,
                    choices: choices,
                    selected: value,
                  );
                  if (picked != null) onChanged!(picked);
                },
          excludeFromSemantics: true,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: extent),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      current?.label ?? '',
                      style: _controlStyle(context),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.expand_more, color: roles.secondaryText),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
