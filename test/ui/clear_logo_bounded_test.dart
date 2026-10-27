import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/ui/app_ui.dart';

void main() {
  for (final padded in [false, true]) {
    testWidgets(
      'every frame has fallback or the validated bounded logo ($padded)',
      (tester) async {
        final bytes = await tester.runAsync(() async {
          final recorder = ui.PictureRecorder();
          Canvas(recorder).drawRect(
            padded
                ? const Rect.fromLTWH(760, 200, 2280, 600)
                : const Rect.fromLTWH(0, 0, 3800, 1000),
            Paint()..color = Colors.white,
          );
          final picture = recorder.endRecording();
          final image = await picture.toImage(3800, 1000);
          try {
            return (await image.toByteData(format: ui.ImageByteFormat.png))!
                .buffer
                .asUint8List();
          } finally {
            image.dispose();
            picture.dispose();
          }
        });
        PaintingBinding.instance.imageCache
          ..clear()
          ..clearLiveImages();
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(devicePixelRatio: 2),
              child: Center(
                child: ClearLogoImage(
                  bytes!,
                  maximumSize: const Size(420, 64),
                  minimumVisibleSize: const Size(96, 28),
                  fallback: const Text('Readable title'),
                ),
              ),
            ),
          ),
        );
        ui.Image? ready;
        for (var frame = 0; frame < 40; frame++) {
          final fallback = find.text('Readable title').evaluate().isNotEmpty;
          final images = tester.widgetList<RawImage>(find.byType(RawImage));
          final image = images.isEmpty ? null : images.single.image;
          expect(
            fallback || image != null,
            isTrue,
            reason: 'empty frame $frame',
          );
          if (image != null) {
            expect(image.width, lessThanOrEqualTo(840));
            expect(image.height, lessThanOrEqualTo(128));
            expect(find.byType(Image), findsNothing);
            ready = image;
            break;
          }
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(ready, isNotNull, reason: 'bounded logo never became ready');
        // Compare the crop with alpha on the exact handle supplied to RawImage.
        final pixels = await tester.runAsync(
          () => ready!.toByteData(format: ui.ImageByteFormat.rawRgba),
        );
        var left = ready!.width, right = -1, top = ready.height, bottom = -1;
        for (var y = 0; y < ready.height; y++) {
          for (var x = 0; x < ready.width; x++) {
            if (pixels!.getUint8((y * ready.width + x) * 4 + 3) < 32) continue;
            if (x < left) left = x;
            if (x > right) right = x;
            if (y < top) top = y;
            if (y > bottom) bottom = y;
          }
        }
        expect(right, greaterThanOrEqualTo(left));
        final fitted = applyBoxFit(
          BoxFit.contain,
          const Size(3800, 1000),
          const Size(420, 64),
        ).destination;
        final fractionWidth =
            ((right + 2).clamp(0, ready.width) -
                (left - 1).clamp(0, ready.width)) /
            ready.width;
        final fractionHeight =
            ((bottom + 2).clamp(0, ready.height) -
                (top - 1).clamp(0, ready.height)) /
            ready.height;
        final actual = tester.getSize(find.byType(ClearLogoImage));
        expect(actual.width, closeTo(fitted.width * fractionWidth, .01));
        expect(actual.height, closeTo(fitted.height * fractionHeight, .01));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
