import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';

void main() {
  for (final window in const [
    Size(1280, 720),
    Size(1366, 768),
    Size(1920, 1080),
    Size(3840, 2160),
  ]) {
    testWidgets('canvas paints and receives input across $window', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.5;
      tester.view.physicalSize = window * 1.5;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      late MediaQueryData reported;
      var taps = 0;
      const target = Key('canvas-bottom-action');
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: const EdgeInsets.all(16),
              viewPadding: const EdgeInsets.all(24),
              viewInsets: const EdgeInsets.only(bottom: 80),
              systemGestureInsets: const EdgeInsets.all(8),
              textScaler: const TextScaler.linear(1.5),
            ),
            child: LineupCanvas(reduceMotion: true, child: child!),
          ),
          home: Builder(
            builder: (context) {
              reported = MediaQuery.of(context);
              return Stack(
                children: [
                  Positioned(
                    right: 30,
                    bottom: 30,
                    child: SizedBox(
                      width: 100,
                      height: 50,
                      child: GestureDetector(
                        key: target,
                        onTap: () => taps++,
                        child: const ColoredBox(color: Colors.red),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
      final scale = LineupCanvas.scaleFor(window);
      expect(reported.size, window / scale);
      expect(reported.devicePixelRatio, 1.5);
      expect(reported.textScaler.scale(18), 27);
      expect(reported.padding, const EdgeInsets.all(16) / scale);
      expect(reported.viewPadding, const EdgeInsets.all(24) / scale);
      expect(reported.viewInsets, const EdgeInsets.only(bottom: 80) / scale);
      expect(reported.systemGestureInsets, const EdgeInsets.all(8) / scale);
      expect(reported.disableAnimations, isTrue);
      final box = tester.renderObject<RenderBox>(find.byKey(target));
      final bounds = MatrixUtils.transformRect(
        box.getTransformTo(null),
        Offset.zero & box.size,
      );
      expect(bounds.right, closeTo(window.width - 30 * scale, .001));
      expect(bounds.bottom, closeTo(window.height - 30 * scale, .001));
      expect(bounds.width, closeTo(100 * scale, .001));
      await tester.tap(find.byKey(target));
      expect(taps, 1);
    });
  }
}
