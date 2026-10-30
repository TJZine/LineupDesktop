part of 'settings_view.dart';

bool _subtitleUsesColumns(BuildContext context, double detailWidth) =>
    !LineupLayout.isCompactWidth(MediaQuery.sizeOf(context).width) &&
    MediaQuery.textScalerOf(context).scale(1) < 2 &&
    detailWidth * .54 - 32 >= 560;

({double height, double gap}) _subtitlePreviewCrop({
  required double availableHeight,
  required double frameHeight,
  required double rowHeight,
  required double clearance,
  required bool columns,
  required bool scrollingHeading,
}) {
  if (scrollingHeading) return (height: 0, gap: 0);
  final available = math.max(0.0, availableHeight);
  final requested = columns
      ? math.min(math.max(0.0, available - 24), .72 * frameHeight)
      : .36 * frameHeight;
  final budget = math.max(0.0, available - rowHeight - clearance);
  final gap = columns ? 0.0 : math.min(8.0, budget);
  return (
    height: columns
        ? math.min(requested, available)
        : math.min(requested, math.max(0.0, budget - gap)),
    gap: gap,
  );
}

extension _SubtitleSettingsPage on _SettingsViewState {
  FocusNode _subtitleNode(_SettingKey key) =>
      _subtitleFocus.putIfAbsent(key, () => FocusNode(debugLabel: key.name));

  Widget _subtitleDetail(BuildContext context) {
    final style = _displaySettings.subtitleStyle;
    final android = defaultTargetPlatform == TargetPlatform.android;
    final device = android && style.useDeviceStyle;
    final snapshot = widget.subtitleAppearance?.deviceCaptions;
    final appearance = device && snapshot != null
        ? snapshot.resolve(style)
        : style.resolve();
    Widget row(
      _SettingKey key,
      String label,
      Widget control, {
      bool enabled = true,
      String? helper,
      bool toggle = false,
      bool action = false,
    }) => _SubtitleSettingRow(
      key: ValueKey('subtitle-row-${key.name}'),
      label: label,
      helper: helper,
      enabled: enabled,
      toggle: toggle,
      action: action,
      feedback: _settingFeedback(key),
      control: control,
      focusNode: _subtitleNode(key),
      revealToken: _subtitleHeadingScrollRow,
      onMeasured: (height, focused, align) =>
          _subtitleMeasured(key, height, focused, align),
    );
    Widget dropdown<T>(
      _SettingKey key,
      String label,
      String spoken,
      T value,
      List<T> values,
      String Function(T) name,
      SubtitleStyle Function(SubtitleStyle, T) change, {
      bool enabled = true,
      String? displayed,
      bool custom = false,
      bool font = false,
    }) => row(
      key,
      label,
      Semantics(
        label: spoken,
        enabled: enabled,
        child: lineupDropdownField<T>(
          context: context,
          key: ValueKey('subtitle-field-${key.name}'),
          focusNode: _subtitleNode(key),
          initialValue: value,
          isDense: false,
          itemHeight: null,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 18),
          icon: const Icon(Icons.arrow_drop_down, size: 20),
          selectedItemChildren: [
            for (final item in values) Text(displayed ?? name(item)),
            if (custom) const Text('Custom'),
          ],
          items: [
            for (final item in values)
              DropdownMenuItem<T>(
                value: item,
                child: font
                    ? _SubtitleFontName(font: item as SubtitleFont)
                    : Text(name(item)),
              ),
            if (custom)
              DropdownMenuItem<T>(enabled: false, child: Text('Custom')),
          ],
          onChanged: enabled
              ? (item) {
                  if (item != null) {
                    _changeSubtitle(key, (current) => change(current, item));
                  }
                }
              : null,
        ),
      ),
      enabled: enabled,
    );
    Widget toggle(
      _SettingKey key,
      String label,
      bool value,
      SubtitleStyle Function(SubtitleStyle, bool) change, {
      String? helper,
    }) => row(
      key,
      label,
      Semantics(
        label: label == 'Bold' ? 'Text Bold' : label,
        child: SizedBox(
          height: 48,
          child: Switch(
            key: ValueKey('subtitle-field-${key.name}'),
            focusNode: _subtitleNode(key),
            value: value,
            padding: EdgeInsets.zero,
            onChanged: (item) =>
                _changeSubtitle(key, (current) => change(current, item)),
          ),
        ),
      ),
      helper: helper,
      toggle: true,
    );
    final children = <Widget>[
      if (android)
        toggle(
          _SettingKey.subtitleDevice,
          'Use device subtitle settings',
          style.useDeviceStyle,
          (s, v) => s.copyWith(useDeviceStyle: v),
          helper: snapshot?.enabled == false
              ? 'Uses the style from Android settings. Captions are off there; Lineup uses their style anyway.'
              : 'Uses the caption style from Android settings. Position and Bold stay here.',
        ),
      // Custom is a status, never a selectable value. Use the first enabled
      // preset as the menu anchor while the selected child displays Custom.
      dropdown(
        _SettingKey.subtitlePreset,
        'Style',
        'Style',
        style.preset ?? SubtitlePreset.standard,
        SubtitlePreset.values,
        (v) => v.label,
        (s, v) => s.applying(v),
        enabled: !device,
        custom: style.preset == null,
        displayed: style.preset == null ? 'Custom' : null,
      ),
      dropdown(
        _SettingKey.subtitleSize,
        'Size',
        'Size',
        style.size,
        SubtitleSize.values,
        (v) => v.label,
        (s, v) => s.copyWith(size: v),
        enabled: !device,
      ),
      dropdown(
        _SettingKey.subtitlePosition,
        'Position',
        'Position',
        style.position,
        SubtitlePosition.values,
        (v) => v.label,
        (s, v) => s.copyWith(position: v),
      ),
      const _SubtitleGroup('TEXT'),
      dropdown(
        _SettingKey.subtitleTextColor,
        'Color',
        'Text Color',
        style.textColor,
        SubtitleColor.values,
        (v) => v.label,
        (s, v) => s.copyWith(textColor: v),
        enabled: !device,
      ),
      dropdown(
        _SettingKey.subtitleTextOpacity,
        'Opacity',
        'Text Opacity',
        style.textOpacity,
        SubtitleTextOpacity.values,
        (v) => v.label,
        (s, v) => s.copyWith(textOpacity: v),
        enabled: !device,
      ),
      dropdown(
        _SettingKey.subtitleFont,
        'Font',
        'Text Font',
        style.font,
        SubtitleFont.values,
        (v) => v.label,
        (s, v) => s.copyWith(font: v),
        enabled: !device,
        font: true,
      ),
      toggle(
        _SettingKey.subtitleBold,
        'Bold',
        style.bold,
        (s, v) => s.copyWith(bold: v),
      ),
      const _SubtitleGroup('EDGES'),
      dropdown(
        _SettingKey.subtitleEdge,
        'Style',
        'Edge Style',
        style.edge,
        SubtitleEdge.values,
        (v) => v.label,
        (s, v) => s.copyWith(edge: v),
        enabled: !device,
      ),
      dropdown(
        _SettingKey.subtitleEdgeColor,
        'Color',
        'Edge Color',
        style.edgeColor,
        SubtitleColor.values,
        (v) => v.label,
        (s, v) => s.copyWith(edgeColor: v),
        enabled: !device && style.edge != SubtitleEdge.none,
      ),
      const _SubtitleGroup('BACKGROUND (BEHIND EACH LINE)'),
      dropdown(
        _SettingKey.subtitleBackgroundOpacity,
        'Opacity',
        'Background Opacity',
        style.backgroundOpacity,
        SubtitleBoxOpacity.values,
        (v) => v.label,
        (s, v) => s.copyWith(backgroundOpacity: v),
        enabled: !device,
      ),
      dropdown(
        _SettingKey.subtitleBackgroundColor,
        'Color',
        'Background Color',
        style.backgroundColor,
        SubtitleColor.values,
        (v) => v.label,
        (s, v) => s.copyWith(backgroundColor: v),
        enabled: !device && style.backgroundOpacity != SubtitleBoxOpacity.off,
      ),
      const _SubtitleGroup('WINDOW (ONE BOX BEHIND THE CAPTION)'),
      dropdown(
        _SettingKey.subtitleWindowOpacity,
        'Opacity',
        'Window Opacity',
        style.windowOpacity,
        SubtitleBoxOpacity.values,
        (v) => v.label,
        (s, v) => s.copyWith(windowOpacity: v),
        enabled: !device,
      ),
      dropdown(
        _SettingKey.subtitleWindowColor,
        'Color',
        'Window Color',
        style.windowColor,
        SubtitleColor.values,
        (v) => v.label,
        (s, v) => s.copyWith(windowColor: v),
        enabled: !device && style.windowOpacity != SubtitleBoxOpacity.off,
      ),
      const _SubtitleGroup('STYLED SUBTITLES'),
      toggle(
        _SettingKey.subtitleStyled,
        'Apply my style to styled subtitles',
        style.styleStyledSubtitles,
        (s, v) => s.copyWith(styleStyledSubtitles: v),
        helper: 'ASS/SSA dialogue uses your style. Signs and author positioning are dropped.',
      ),
      row(
        _SettingKey.subtitleReset,
        '',
        OutlinedButton(
          key: const ValueKey('subtitle-field-subtitleReset'),
          focusNode: _subtitleNode(_SettingKey.subtitleReset),
          onPressed:
              !_saving(_SettingKey.subtitleReset) &&
                  style.copyWith(useDeviceStyle: false) == const SubtitleStyle()
              ? null
              : () => _changeSubtitle(
                  _SettingKey.subtitleReset,
                  (s) => SubtitleStyle(useDeviceStyle: s.useDeviceStyle),
                ),
          child: const Text('Reset to standard'),
        ),
        enabled:
            _saving(_SettingKey.subtitleReset) ||
            style.copyWith(useDeviceStyle: false) != const SubtitleStyle(),
        action: true,
      ),
    ];
    final firstKey = android
        ? _SettingKey.subtitleDevice
        : _SettingKey.subtitlePreset;
    final rowHeight = _subtitleHeights[_focusedSubtitle ?? firstKey] ?? 100;
    return Focus(
      canRequestFocus: false,
      onKeyEvent: (_, event) {
        if (DeviceProfile.of(context).isTv &&
            event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          (widget.focusNode ?? _subtitleRailFocus).requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: LayoutBuilder(
        key: _subtitlePageKey,
        builder: (context, pageConstraints) {
          final scrollHeading = _subtitleHeadingScrollRow != null;
          _subtitleHeadingIsPinned = !scrollHeading;
          final heading = KeyedSubtree(
            key: _subtitleHeadingKey,
            child: _SettingsSection(
              title: 'Subtitles',
              trailingGap: 16,
              description: _SettingsViewState._categoryDescription(
                SettingsCategory.subtitles,
              ),
              children: const [],
            ),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              scrollHeading
                  ? const SizedBox.shrink(
                      key: ValueKey('subtitle-scrolling-heading'),
                    )
                  : heading,
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final frame = MediaQuery.sizeOf(context).shortestSide;
                    final wide = _subtitleUsesColumns(
                      context,
                      constraints.maxWidth,
                    );
                    final clearance =
                        LineupTheme.of(context).largeFocusIndicators
                        ? LineupFocusFrame.contentClearance * 2
                        : 0.0;
                    // Keep the full reference frame; reserve the complete row
                    // first, then shrink its preview crop and empty gap.
                    final crop = _subtitlePreviewCrop(
                      availableHeight: constraints.maxHeight,
                      frameHeight: frame,
                      rowHeight: rowHeight,
                      clearance: clearance,
                      columns: wide,
                      scrollingHeading: scrollHeading,
                    );
                    final preview = _SubtitlePreview(
                      height: crop.height,
                      frameHeight: frame,
                      appearance: appearance,
                    );
                    // Sixteen fixed controls do not need virtualized rows.
                    // Eager layout keeps their offsets exact while the heading
                    // moves and text reflows during a viewport change.
                    final rows = SingleChildScrollView(
                      key: const ValueKey('subtitle-rows'),
                      padding: EdgeInsets.symmetric(vertical: clearance / 2),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (scrollHeading) heading,
                          // Preserve the old list's per-row paint boundaries,
                          // including input borders at fractional canvas scales.
                          for (final child in children)
                            RepaintBoundary(
                              key: child.key == null
                                  ? null
                                  : ValueKey(('subtitle-paint', child.key)),
                              child: child,
                            ),
                          if (_subtitleRepinningSpace > 0)
                            SizedBox(
                              key: const ValueKey('subtitle-repinning-space'),
                              height: _subtitleRepinningSpace,
                            ),
                        ],
                      ),
                    );
                    return wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: constraints.maxWidth * .54 - 32,
                                height: constraints.maxHeight,
                                child: rows,
                              ),
                              const SizedBox(width: 32),
                              SizedBox(
                                width: constraints.maxWidth * .46,
                                child: preview,
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              preview,
                              SizedBox(height: crop.gap),
                              Expanded(child: rows),
                            ],
                          );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SubtitleGroup extends StatelessWidget {
  const _SubtitleGroup(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      DeviceProfile.of(context).isTv ? 16 : 0,
      24,
      0,
      8,
    ),
    child: Semantics(
      header: true,
      child: Text(
        label,
        style: LineupTypography.small.copyWith(
          letterSpacing: 1.2,
          color: LineupTheme.of(context).mutedText,
        ),
      ),
    ),
  );
}

/// Measures the entire focus context, including asynchronous feedback. The
/// parent crops only the preview, then this row reveals its complete bounds.
class _SubtitleSettingRow extends StatefulWidget {
  const _SubtitleSettingRow({
    required this.label,
    required this.control,
    required this.feedback,
    required this.enabled,
    required this.toggle,
    required this.onMeasured,
    required this.focusNode,
    required this.revealToken,
    this.action = false,
    this.helper,
    super.key,
  });
  final String label;
  final String? helper;
  final Widget control;
  final Widget feedback;
  final bool enabled;
  final bool toggle;
  final bool action;
  final FocusNode focusNode;
  final Object? revealToken;
  final bool Function(
    double height,
    bool focused,
    ValueChanged<double> alignBeforeRepinning,
  )
  onMeasured;
  @override
  State<_SubtitleSettingRow> createState() => _SubtitleSettingRowState();
}

class _SubtitleSettingRowState extends State<_SubtitleSettingRow> {
  double? _lastHeight;
  @override
  void didUpdateWidget(covariant _SubtitleSettingRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revealToken != widget.revealToken) _measure(reveal: true);
  }

  void _measure({bool reveal = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final changed = _lastHeight != box.size.height;
      _lastHeight = box.size.height;
      final managedReveal = widget.onMeasured(
        box.size.height,
        widget.focusNode.hasFocus,
        (previewExtent) {
          final position = Scrollable.of(context).position;
          final clearance = LineupTheme.of(context).largeFocusIndicators
              ? LineupFocusFrame.contentClearance
              : 0.0;
          final viewport = RenderAbstractViewport.of(box);
          final bottom = box
              .localToGlobal(Offset(0, box.size.height), ancestor: viewport)
              .dy;
          final targetBottom =
              position.viewportDimension - previewExtent - clearance;
          // Keep room for the returning preview in current viewport units.
          position.jumpTo(
            (position.pixels + bottom - targetBottom).clamp(
              position.minScrollExtent,
              position.maxScrollExtent,
            ),
          );
        },
      );
      // A heading transition owns its reveal until the new viewport is ready.
      if (!managedReveal && widget.focusNode.hasFocus && (changed || reveal)) {
        final clearance = LineupTheme.of(context).largeFocusIndicators
            ? LineupFocusFrame.contentClearance
            : 0.0;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && widget.focusNode.hasFocus && box.attached) {
            box.showOnScreen(
              rect: (Offset.zero & box.size).inflate(clearance),
              duration: Duration.zero,
            );
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _measure();
    final roles = LineupTheme.of(context);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        _measure(reveal: focused);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.action)
            Padding(
              padding: EdgeInsets.fromLTRB(
                DeviceProfile.of(context).isTv ? 16 : 0,
                24,
                0,
                8,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: widget.control,
              ),
            )
          else
            LineupToggleSurface(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final inset = DeviceProfile.of(context).isTv ? 16.0 : 0.0;
                  final controlWidth = widget.toggle
                      ? 56.0
                      : math.min(280.0, constraints.maxWidth * .55);
                  return Container(
                    constraints: const BoxConstraints(minHeight: 72),
                    padding: EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: inset,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: roles.subtleBorder),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ExcludeSemantics(
                                child: Text(
                                  widget.label,
                                  style: LineupTypography.control.copyWith(
                                    height: 1.2,
                                    color: widget.enabled
                                        ? roles.primaryText
                                        : roles.mutedText,
                                  ),
                                ),
                              ),
                              if (widget.helper != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  widget.helper!,
                                  style: LineupTypography.body.copyWith(
                                    fontSize: 16,
                                    height: 1.4,
                                    color: roles.secondaryText,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 24),
                        SizedBox(width: controlWidth, child: widget.control),
                      ],
                    ),
                  );
                },
              ),
            ),
          widget.feedback,
        ],
      ),
    );
  }
}

class _SubtitleFontName extends StatefulWidget {
  const _SubtitleFontName({required this.font});
  final SubtitleFont font;
  @override
  State<_SubtitleFontName> createState() => _SubtitleFontNameState();
}

class _SubtitleFontNameState extends State<_SubtitleFontName> {
  @override
  void initState() {
    super.initState();
    if (!SubtitleFonts.shared.isReady(widget.font)) {
      unawaited(
        SubtitleFonts.shared.load(widget.font).then((_) {
          if (mounted) setState(() {});
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Text(
    widget.font.label,
    style: TextStyle(
      fontFamily: SubtitleFonts.shared.isReady(widget.font)
          ? widget.font.fontFamily
          : 'Inter',
    ),
  );
}

class _SubtitlePreview extends StatelessWidget {
  const _SubtitlePreview({
    required this.height,
    required this.frameHeight,
    required this.appearance,
  });
  final double height;
  final double frameHeight;
  final SubtitleAppearance appearance;
  static final _cues = ValueNotifier(
    SubtitleCues([
      SubtitleCue(
        align: 2,
        lines: const [
          [SubtitleSegment(text: 'Look out!')],
          [SubtitleSegment(text: '[Door creaks]')],
        ],
      ),
    ]),
  );
  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('subtitle-preview'),
    height: height,
    decoration: BoxDecoration(
      border: Border.all(color: LineupTheme.of(context).subtleBorder),
      borderRadius: BorderRadius.circular(8),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: OverflowBox(
          alignment: Alignment.bottomCenter,
          minHeight: frameHeight,
          maxHeight: frameHeight,
          minWidth: constraints.maxWidth,
          maxWidth: constraints.maxWidth,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xfff1eadb),
                  Color(0xffc9bfa8),
                  Color(0xff4a4136),
                  Color(0xff0c0b09),
                ],
                stops: [0, .38, .62, 1],
              ),
            ),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0x33000000)],
                ),
              ),
              child: SubtitleLayer(
                cues: _cues,
                appearance: _FixedSubtitleAppearance(appearance),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A build-scoped value, without a mutable notifier or playback publication.
class _FixedSubtitleAppearance implements ValueListenable<SubtitleAppearance> {
  const _FixedSubtitleAppearance(this.value);
  @override
  final SubtitleAppearance value;
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}
