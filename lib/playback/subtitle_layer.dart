import 'dart:async';

import 'package:flutter/foundation.dart';
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
          _readFontAsset(
            'assets/fonts/subtitles/${font.storageKey}/$weight.ttf',
          ),
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

  // AssetBundle implementations may return SynchronousFuture (including
  // Flutter's test bundle). Future.wait requires asynchronous then callbacks;
  // normalize here, also capturing synchronous throws from either weight.
  Future<ByteData> _readFontAsset(String path) async => _assets.load(path);
}

/// Transparent, noninteractive paint over the entire presentation rectangle.
class SubtitleLayer extends StatefulWidget {
  const SubtitleLayer({
    required this.cues,
    required this.appearance,
    this.fonts,
    super.key,
  });
  final ValueListenable<SubtitleCues> cues;
  final ValueListenable<SubtitleAppearance> appearance;
  final SubtitleFonts? fonts;

  @override
  State<SubtitleLayer> createState() => _SubtitleLayerState();
}

class _SubtitleLayerState extends State<SubtitleLayer> {
  SubtitleFonts get _fonts => widget.fonts ?? SubtitleFonts.shared;
  SubtitleFont? _requested;

  @override
  Widget build(BuildContext context) => IgnorePointer(
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
                return CustomPaint(
                  painter: SubtitlePainter(
                    cues: cues,
                    appearance: appearance,
                    fontFamily: _fonts.isReady(font)
                        ? font.fontFamily
                        : 'Inter',
                  ),
                  child: const SizedBox.expand(),
                );
              },
            ),
      ),
    ),
  );
}

/// Provisional §6.4 metrics; final look/OSD avoidance belongs to the UI gate.
class SubtitlePainter extends CustomPainter {
  SubtitlePainter({
    required this.cues,
    required this.appearance,
    required this.fontFamily,
  });
  final SubtitleCues cues;
  final SubtitleAppearance appearance;
  final String fontFamily;

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
      final offset = origin(cue, size, text.size);
      canvas.drawRect(
        (offset & text.size).inflate(.25 * em),
        Paint()..color = Color(appearance.windowColor),
      );
      // Group selection boxes by visual line, including wrapped lines. This
      // preserves tight line boxes with horizontal padding, behind all edges.
      final lines = <double, Rect>{};
      for (final box in text.getBoxesForSelection(
        TextSelection(
          baseOffset: 0,
          extentOffset: text.text!.toPlainText().length,
        ),
      )) {
        final rect = box.toRect();
        lines[rect.top] = lines[rect.top]?.expandToInclude(rect) ?? rect;
      }
      for (final rect in lines.values) {
        canvas.drawRect(
          Rect.fromLTRB(
            rect.left - .1 * em,
            rect.top,
            rect.right + .1 * em,
            rect.bottom,
          ).shift(offset),
          Paint()..color = Color(appearance.backgroundColor),
        );
      }
      if (appearance.edge == SubtitleEdge.outline) {
        final outline = layout(
          cue,
          size,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = .06 * em
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
            offset: Offset(.05 * em, .05 * em),
            blurRadius: .025 * em,
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
      fontFamily != oldDelegate.fontFamily;
}
