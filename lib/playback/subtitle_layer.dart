import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../settings/subtitle_style.dart';
import 'subtitle_cues.dart';

/// Process-cached font data only; it has no settings, media or device listener.
class SubtitleFonts {
  SubtitleFonts({AssetBundle? assets}) : _assets = assets ?? rootBundle;
  static final shared = SubtitleFonts();
  final AssetBundle _assets;
  final _loads = <SubtitleFont, Future<bool>>{};
  final _ready = <SubtitleFont>{SubtitleFont.standard};
  bool isReady(SubtitleFont font) => _ready.contains(font);

  Future<bool> load(SubtitleFont font) => _loads.putIfAbsent(font, () async {
    if (font == SubtitleFont.standard) return true;
    try {
      // Observe both asset futures together: one missing weight must not leave
      // the other failure unhandled while playback continues with Standard.
      final data = await Future.wait([
        for (final weight in ['Regular', 'Bold'])
          _assets.load('assets/fonts/subtitles/${font.storageKey}/$weight.ttf'),
      ]);
      final loader = FontLoader(font.fontFamily);
      for (final bytes in data) {
        loader.addFont(Future.value(bytes));
      }
      await loader.load();
      _ready.add(font);
      return true;
    } catch (_) {
      // Optional appearance cannot interrupt playback. Standard stays available.
      return false;
    }
  });
}

/// The material-paint bounds of the bottom panels that currently overlap the
/// presentation. The rectangles are in the [SubtitleLayer]'s coordinates.
@immutable
final class SubtitlePanelAvoidanceState {
  const SubtitlePanelAvoidanceState._(this.panels);

  const SubtitlePanelAvoidanceState.empty() : panels = const [];

  final List<Rect> panels;

  double? get highestPanelTop {
    if (panels.isEmpty) return null;
    var top = panels.first.top;
    for (final panel in panels.skip(1)) {
      top = math.min(top, panel.top);
    }
    return top;
  }
}

/// Tracks current and retiring bottom-panel geometry without rebuilding the
/// Player when cue values change.
final class SubtitlePanelAvoidance
    extends ValueNotifier<SubtitlePanelAvoidanceState> {
  SubtitlePanelAvoidance() : super(const SubtitlePanelAvoidanceState.empty());

  final _panels = <Object, Rect>{};
  var _disposed = false;

  void update(Object id, Rect bounds) {
    if (_disposed) return;
    if (_panels[id] == bounds) return;
    _panels[id] = bounds;
    _publish();
  }

  void remove(Object id) {
    if (_disposed) return;
    if (_panels.remove(id) == null) return;
    _publish();
  }

  void _publish() {
    if (_disposed) return;
    value = SubtitlePanelAvoidanceState._(
      List<Rect>.unmodifiable(_panels.values),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _panels.clear();
    super.dispose();
  }
}

/// Reports a panel's painted top, including the material painter's feather,
/// in the presentation rectangle's coordinate space.
class SubtitlePanelReporter extends SingleChildRenderObjectWidget {
  const SubtitlePanelReporter({
    required this.avoidance,
    required this.presentationKey,
    required this.feather,
    required super.child,
    super.key,
  });

  final SubtitlePanelAvoidance avoidance;
  final GlobalKey presentationKey;
  final double feather;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _SubtitlePanelReporterRenderObject(
        avoidance: avoidance,
        presentationKey: presentationKey,
        feather: feather,
      );

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _SubtitlePanelReporterRenderObject).update(
      avoidance: avoidance,
      presentationKey: presentationKey,
      feather: feather,
    );
  }
}

class _SubtitlePanelReporterRenderObject extends RenderProxyBox {
  _SubtitlePanelReporterRenderObject({
    required this._avoidance,
    required this._presentationKey,
    required this._feather,
  });

  SubtitlePanelAvoidance _avoidance;
  GlobalKey _presentationKey;
  double _feather;
  var _reportScheduled = false;

  void update({
    required SubtitlePanelAvoidance avoidance,
    required GlobalKey presentationKey,
    required double feather,
  }) {
    if (!identical(_avoidance, avoidance)) {
      final previous = _avoidance;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        previous.remove(this);
      });
      _avoidance = avoidance;
    }
    _presentationKey = presentationKey;
    _feather = feather;
    _scheduleReport();
  }

  void _scheduleReport() {
    if (_reportScheduled) return;
    _reportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportScheduled = false;
      if (!attached || !hasSize) return;
      final presentation = _presentationKey.currentContext?.findRenderObject();
      if (presentation is! RenderBox || !presentation.hasSize) return;
      final topLeft = presentation.globalToLocal(
        localToGlobal(Offset(0, -_feather)),
      );
      final topRight = presentation.globalToLocal(
        localToGlobal(Offset(size.width, -_feather)),
      );
      _avoidance.update(this, Rect.fromPoints(topLeft, topRight));
    });
  }

  @override
  void performLayout() {
    super.performLayout();
    _scheduleReport();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    // AnimatedSwitcher can move a child without laying it out again.
    _scheduleReport();
  }

  @override
  void detach() {
    final avoidance = _avoidance;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!attached) avoidance.remove(this);
    });
    super.detach();
  }
}

/// Transparent, noninteractive paint over the entire presentation rectangle.
class SubtitleLayer extends StatefulWidget {
  const SubtitleLayer({
    required this.cues,
    required this.appearance,
    this.fonts,
    this.avoidance,
    this.presentationKey,
    super.key,
  });
  final ValueListenable<SubtitleCues> cues;
  final ValueListenable<SubtitleAppearance> appearance;
  final SubtitleFonts? fonts;
  final SubtitlePanelAvoidance? avoidance;
  final GlobalKey? presentationKey;

  @override
  State<SubtitleLayer> createState() => _SubtitleLayerState();
}

class _SubtitleLayerState extends State<SubtitleLayer> {
  SubtitleFonts get _fonts => widget.fonts ?? SubtitleFonts.shared;
  SubtitleFont? _requested;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    key: widget.presentationKey,
    child: ExcludeSemantics(
      child: ValueListenableBuilder<SubtitleCues>(
        valueListenable: widget.cues,
        builder: (context, cues, _) =>
            ValueListenableBuilder<SubtitleAppearance>(
              valueListenable: widget.appearance,
              builder: (context, appearance, _) {
                if (cues.isEmpty) return const SizedBox.expand();
                final font = appearance.font;
                if (!_fonts.isReady(font) && _requested != font) {
                  _requested = font;
                  unawaited(
                    _fonts.load(font).then((_) {
                      if (mounted) setState(() {});
                    }),
                  );
                }
                Widget paintLayer(SubtitlePanelAvoidanceState? avoidance) =>
                    CustomPaint(
                      painter: SubtitlePainter(
                        cues: cues,
                        appearance: appearance,
                        fontFamily: _fonts.isReady(font)
                            ? font.fontFamily
                            : 'Inter',
                        avoidance: avoidance,
                      ),
                      child: const SizedBox.expand(),
                    );
                final avoidance = widget.avoidance;
                return avoidance == null
                    ? paintLayer(null)
                    : ValueListenableBuilder<SubtitlePanelAvoidanceState>(
                        valueListenable: avoidance,
                        builder: (context, state, _) => paintLayer(state),
                      );
              },
            ),
      ),
    ),
  );
}

/// Subtitle paint metrics and the optional full-Player panel avoidance.
class SubtitlePainter extends CustomPainter {
  SubtitlePainter({
    required this.cues,
    required this.appearance,
    required this.fontFamily,
    this.avoidance,
  });
  final SubtitleCues cues;
  final SubtitleAppearance appearance;
  final String fontFamily;
  final SubtitlePanelAvoidanceState? avoidance;

  static const outlineStrokeEm = .10;
  static const shadowOffsetEm = .06;
  static const shadowBlurEm = .06;
  static const backgroundInsetEm = .2;

  double emFor(Size size) => .0533 * appearance.scale * size.height;

  TextPainter layout(
    SubtitleCue cue,
    Size size, {
    Paint? foreground,
    List<Shadow>? shadows,
  }) {
    final em = emFor(size);
    final column = (cue.align - 1) % 3;
    return TextPainter(
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      textAlign: [TextAlign.left, TextAlign.center, TextAlign.right][column],
      text: TextSpan(
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: em,
          height: 1.2,
          color: foreground == null ? Color(appearance.textColor) : null,
          foreground: foreground,
          shadows: shadows,
          fontWeight: appearance.bold ? FontWeight.bold : FontWeight.normal,
        ),
        children: [
          for (var i = 0; i < cue.lines.length; i++) ...[
            if (i > 0) const TextSpan(text: '\n'),
            for (final segment in cue.lines[i])
              TextSpan(
                text: segment.text,
                style: TextStyle(
                  fontStyle: segment.italic
                      ? FontStyle.italic
                      : FontStyle.normal,
                  fontWeight: appearance.bold || segment.bold
                      ? FontWeight.bold
                      : FontWeight.normal,
                  decoration: segment.underline
                      ? TextDecoration.underline
                      : null,
                ),
              ),
          ],
        ],
      ),
    )..layout(maxWidth: size.width * .9);
  }

  Offset origin(SubtitleCue cue, Size size, Size block) {
    final column = (cue.align - 1) % 3;
    final row = (cue.align - 1) ~/ 3;
    final margin = size.height * .06;
    final x = [
      size.width * .05,
      (size.width - block.width) / 2,
      size.width * .95 - block.width,
    ][column];
    final y = [
      size.height - margin - block.height,
      (size.height - block.height) / 2,
      margin,
    ][row];
    // Position adds bottom clearance. Embedded top/center anchors keep their
    // positions, so raising bottom captions cannot move a top cue offscreen.
    final raise = row == 0 ? appearance.raise * size.height : 0.0;
    return Offset(x, y - raise);
  }

  List<Rect> _lineBounds(TextPainter text, Offset offset) {
    final lines = <double, Rect>{};
    for (final box in text.getBoxesForSelection(
      TextSelection(
        baseOffset: 0,
        extentOffset: text.text!.toPlainText().length,
      ),
    )) {
      final rect = box.toRect().shift(offset);
      lines[rect.top] = lines[rect.top]?.expandToInclude(rect) ?? rect;
    }
    return lines.values.toList(growable: false);
  }

  Rect _paintedBounds(TextPainter text, Offset offset, double em) {
    var bounds = offset & text.size;
    if (Color(appearance.windowColor).a > 0) {
      bounds = bounds.inflate(.25 * em);
    }
    if (Color(appearance.backgroundColor).a > 0) {
      for (final line in _lineBounds(text, offset)) {
        bounds = bounds.expandToInclude(
          Rect.fromLTRB(
            line.left - backgroundInsetEm * em,
            line.top,
            line.right + backgroundInsetEm * em,
            line.bottom,
          ),
        );
      }
    }
    if (Color(appearance.edgeColor).a > 0) {
      final edgeOutset = switch (appearance.edge) {
        SubtitleEdge.outline => outlineStrokeEm / 2,
        SubtitleEdge.dropShadow => shadowOffsetEm + shadowBlurEm,
        SubtitleEdge.raised || SubtitleEdge.depressed => .03,
        SubtitleEdge.none => 0.0,
      };
      bounds = bounds.inflate(edgeOutset * em);
    }
    return bounds;
  }

  /// Returns the painted block, including visible boxes and edge outsets.
  Rect renderedBlockBounds(SubtitleCue cue, Size size) {
    final text = layout(cue, size);
    final bounds = _paintedBounds(
      text,
      origin(cue, size, text.size),
      emFor(size),
    );
    text.dispose();
    return bounds;
  }

  double clearanceLift(SubtitleCue cue, Size size, {required double panelTop}) {
    if ((cue.align - 1) ~/ 3 != 0) return 0;
    final text = layout(cue, size);
    final bounds = _paintedBounds(
      text,
      origin(cue, size, text.size),
      emFor(size),
    );
    text.dispose();
    return math.max(0, bounds.bottom - (panelTop - .02 * size.height));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final em = emFor(size);
    final edgeColor = Color(appearance.edgeColor);
    final textAlpha = (Color(appearance.textColor).a * 255).round();
    final edgeAlpha = (edgeColor.a * 255).round();
    final edge = edgeColor.withAlpha(
      edgeAlpha < textAlpha ? edgeAlpha : textAlpha,
    );
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final cue in cues.cues) {
      if (!cue.lines.any(
        (line) => line.any((segment) => segment.text.isNotEmpty),
      )) {
        continue;
      }
      final text = layout(cue, size);
      var offset = origin(cue, size, text.size);
      final panelTop = avoidance?.highestPanelTop;
      if (panelTop != null && (cue.align - 1) ~/ 3 == 0) {
        offset = offset.translate(
          0,
          -clearanceLift(cue, size, panelTop: panelTop),
        );
      }
      canvas.drawRect(
        (offset & text.size).inflate(.25 * em),
        Paint()..color = Color(appearance.windowColor),
      );
      // Group selection boxes by visual line, including wrapped lines. This
      // preserves tight line boxes with horizontal padding, behind all edges.
      for (final rect in _lineBounds(text, offset)) {
        canvas.drawRect(
          Rect.fromLTRB(
            rect.left - backgroundInsetEm * em,
            rect.top,
            rect.right + backgroundInsetEm * em,
            rect.bottom,
          ),
          Paint()..color = Color(appearance.backgroundColor),
        );
      }
      if (appearance.edge == SubtitleEdge.outline) {
        final outline = layout(
          cue,
          size,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = outlineStrokeEm * em
            ..strokeJoin = StrokeJoin.round
            ..color = edge,
        );
        outline.paint(canvas, offset);
        outline.dispose();
      }
      final shadows = switch (appearance.edge) {
        SubtitleEdge.dropShadow => [
          Shadow(
            color: edge,
            offset: Offset(shadowOffsetEm * em, shadowOffsetEm * em),
            blurRadius: shadowBlurEm * em,
          ),
        ],
        SubtitleEdge.raised || SubtitleEdge.depressed => [
          Shadow(
            color: Color(0xffffffff).withAlpha(
              edge.a == 0 ? 0 : (Color(appearance.textColor).a * 255).round(),
            ),
            offset: Offset(
              (appearance.edge == SubtitleEdge.raised ? -.03 : .03) * em,
              (appearance.edge == SubtitleEdge.raised ? -.03 : .03) * em,
            ),
          ),
          Shadow(
            color: edge,
            offset: Offset(
              (appearance.edge == SubtitleEdge.raised ? .03 : -.03) * em,
              (appearance.edge == SubtitleEdge.raised ? .03 : -.03) * em,
            ),
          ),
        ],
        _ => null,
      };
      if (shadows == null) {
        text.paint(canvas, offset);
      } else {
        final fill = layout(cue, size, shadows: shadows);
        fill.paint(canvas, offset);
        fill.dispose();
      }
      text.dispose();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(SubtitlePainter oldDelegate) =>
      !identical(cues, oldDelegate.cues) ||
      !identical(appearance, oldDelegate.appearance) ||
      !identical(avoidance, oldDelegate.avoidance) ||
      fontFamily != oldDelegate.fontFamily;
}
