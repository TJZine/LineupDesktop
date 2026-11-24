import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> expectTextPaintersReleased(
  WidgetTester tester,
  Future<void> Function() exercise,
) async {
  final live = Set<TextPainter>.identity();
  var sawCreation = false;
  void observe(ObjectEvent event) {
    final painter = event.object;
    if (painter is! TextPainter) return;
    if (event is ObjectCreated) {
      sawCreation = true;
      live.add(painter);
    } else if (event is ObjectDisposed) {
      live.remove(painter);
    }
  }

  FlutterMemoryAllocations.instance.addListener(observe);
  try {
    await exercise();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(sawCreation, isTrue, reason: 'Expected a TextPainter allocation.');
    expect(
      live.length,
      0,
      reason:
          'Use TextMeasure or TextPainter.computeWidth for measurements '
          'so every temporary TextPainter is disposed.',
    );
  } finally {
    FlutterMemoryAllocations.instance.removeListener(observe);
  }
}
