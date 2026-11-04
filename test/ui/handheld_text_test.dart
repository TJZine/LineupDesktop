import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/ui/handheld_text.dart';

void main() {
  testWidgets('nonlinear scaling fits only the over-wide word', (tester) async {
    await _pump(tester, 100, const HandheldWordText('Hi MMMM'));
    final paragraph = _paragraph(tester);
    final short = _glyphs(paragraph, 0, 2);
    final fitted = _glyphs(paragraph, 3, 7);
    expect(short, hasLength(2));
    expect(short.first.width, closeTo(27, .01));
    expect(fitted, hasLength(4));
    expect(fitted.map((glyph) => glyph.top).toSet(), hasLength(1));
    expect(fitted.first.width, closeTo(25, .01));
    expect(fitted.last.right, lessThanOrEqualTo(100.01));
    expect(fitted.first.top, greaterThan(short.first.top));
  });

  testWidgets('ellipsis keeps floor-sized glyphs and full semantics once', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    const original = 'MMMMMMMM';
    await _pump(tester, 80, const HandheldWordText(original));
    final paragraph = _paragraph(tester);
    expect(paragraph.text.toPlainText(), 'MMM…');
    final glyphs = _glyphs(paragraph, 0, 4);
    expect(glyphs, hasLength(4));
    expect(glyphs.map((glyph) => glyph.top).toSet(), hasLength(1));
    expect(glyphs.first.width, closeTo(18, .01));
    expect(glyphs.last.right, lessThanOrEqualTo(80));
    expect(find.semantics.byLabel(original), findsOne);
    handle.dispose();
  });

  testWidgets('last resort breaks an unfit word at its unscaled size', (
    tester,
  ) async {
    await _pump(
      tester,
      80,
      const HandheldWordText(
        'MMMMMMMM',
        unfitWord: HandheldUnfitWord.lastResortBreak,
      ),
    );
    final glyphs = _glyphs(_paragraph(tester), 0, 8);
    expect(glyphs, hasLength(8));
    expect(glyphs.map((glyph) => glyph.top).toSet(), hasLength(2));
    expect(glyphs.every((glyph) => (glyph.width - 18).abs() < .01), isTrue);
  });

  testWidgets('breakAfter allows a line break after a visible separator', (
    tester,
  ) async {
    await _pump(tester, 100, const HandheldWordText('AB/CD', breakAfter: '/'));
    final paragraph = _paragraph(tester);
    final visual = paragraph.text.toPlainText();
    final first = _glyphs(
      paragraph,
      0,
      visual.indexOf('C'),
    ).where((glyph) => glyph.width > 0).toList();
    final second = _glyphs(paragraph, visual.indexOf('C'), visual.length);
    expect(first, hasLength(3));
    expect(second, hasLength(2));
    expect(first.map((glyph) => glyph.top).toSet(), hasLength(1));
    expect(second.map((glyph) => glyph.top).toSet(), hasLength(1));
    expect(second.first.top, greaterThan(first.first.top));
    expect(first.first.width, closeTo(27, .01));
    expect(second.first.width, closeTo(27, .01));

    await _pump(tester, 100, const HandheldWordText('AB/CD'));
    final unbroken = _paragraph(tester);
    final glyphs = _glyphs(
      unbroken,
      0,
      unbroken.text.toPlainText().length,
    ).where((glyph) => glyph.width > 0).toList();
    expect(glyphs, hasLength(5));
    expect(glyphs.map((glyph) => glyph.top).toSet(), hasLength(1));
  });

  testWidgets('explicit width supports intrinsic height and centered text', (
    tester,
  ) async {
    await _pump(
      tester,
      200,
      const IntrinsicHeight(
        child: HandheldWordText(
          'Hi\nMMMM',
          maxWidth: 100,
          textAlign: TextAlign.center,
        ),
      ),
    );
    final paragraph = _paragraph(tester);
    final short = _glyphs(paragraph, 0, 2);
    final fitted = _glyphs(paragraph, 3, 7);
    expect(paragraph.size.width, 100);
    expect(short.first.left, closeTo((100 - 54) / 2, .01));
    expect(fitted, hasLength(4));
    expect(fitted.map((glyph) => glyph.top).toSet(), hasLength(1));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(WidgetTester tester, double width, Widget text) =>
    tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: _NonlinearScaler()),
          child: DefaultTextStyle(
            style: const TextStyle(fontFamily: 'Ahem', fontSize: 18),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: Align(child: text),
              ),
            ),
          ),
        ),
      ),
    );

RenderParagraph _paragraph(WidgetTester tester) =>
    tester.renderObject<RenderParagraph>(find.byType(RichText));

List<Rect> _glyphs(RenderParagraph paragraph, int start, int end) => [
  for (var index = start; index < end; index++)
    for (final box in paragraph.getBoxesForSelection(
      TextSelection(baseOffset: index, extentOffset: index + 1),
    ))
      box.toRect(),
];

class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();

  @override
  double scale(double fontSize) => fontSize * (fontSize >= 18 ? 1.5 : 2);

  @override
  double get textScaleFactor => 2;
}
