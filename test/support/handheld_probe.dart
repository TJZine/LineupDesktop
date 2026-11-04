import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/ui/lineup_controls.dart';

/// Reveals a control before auditing its transformed reach and center hit.
Future<void> expectHandheldReachable(
  WidgetTester tester,
  Finder control, {
  bool touch = false,
}) async {
  expect(control, findsOneWidget);
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  expectHandheldTarget(tester, control, touch: touch);
}

/// Audits the current painted target without moving its scrollable.
void expectHandheldTarget(
  WidgetTester tester,
  Finder control, {
  bool touch = false,
}) {
  expect(control, findsOneWidget);
  final box = tester.renderObject<RenderBox>(control);
  final bounds = MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
  if (touch) {
    expect(bounds.width, greaterThanOrEqualTo(48 - .01), reason: '$control');
    expect(bounds.height, greaterThanOrEqualTo(48 - .01), reason: '$control');
  }
  final dpr = tester.view.devicePixelRatio;
  final window = tester.view.physicalSize / dpr;
  final keyboard = tester.view.viewInsets.bottom / dpr;
  expect(
    bounds.left,
    greaterThanOrEqualTo(-.5),
    reason: '$control bounds $bounds',
  );
  expect(
    bounds.top,
    greaterThanOrEqualTo(-.5),
    reason: '$control bounds $bounds',
  );
  expect(
    bounds.right,
    lessThanOrEqualTo(window.width + .5),
    reason: '$control bounds $bounds',
  );
  expect(
    bounds.bottom,
    lessThanOrEqualTo(window.height - keyboard + .5),
    reason: '$control bounds $bounds',
  );
  final hits = HitTestResult();
  tester.binding.hitTestInView(hits, bounds.center, tester.view.viewId);
  expect(
    tester.widget(control) is LineupTouchTarget
        ? control.hitTestable().evaluate().isNotEmpty
        : hits.path.any((hit) {
            for (
              var node = hit.target;
              node is RenderObject;
              node = node.parent!
            ) {
              if (identical(node, box)) return true;
              if (node.parent == null) break;
            }
            return false;
          }),
    isTrue,
    reason: '$control center is covered',
  );
}

/// Verifies that each word's rendered glyph boxes share a line.
void expectHandheldWords(Iterable<RenderParagraph> paragraphs) {
  for (final paragraph in paragraphs) {
    final content = paragraph.text.toPlainText();
    for (final word in RegExp(r'[^\s-]+').allMatches(content)) {
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: word.start, extentOffset: word.end),
      );
      expect(
        boxes.map((box) => box.bottom).toSet(),
        hasLength(1),
        reason: '${word.group(0)} in $content',
      );
    }
  }
}
