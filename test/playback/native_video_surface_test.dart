import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/native_video_surface.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';

import '../support/test_doubles.dart';

void main() {
  testWidgets(
    'projects global logical bounds, DPR, deduplication, and teardown',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final player = FakeNativePlayer();

      Widget surface() => MaterialApp(
        home: Stack(
          children: [
            Positioned(
              left: 40,
              top: 50,
              width: 200,
              height: 100,
              child: NativeVideoSurface(player: player),
            ),
          ],
        ),
      );

      await tester.pumpWidget(surface());
      await tester.pump();

      expect(player.videoRects, [
        const PlayerVideoRect(
          left: 40,
          top: 50,
          width: 200,
          height: 100,
          scale: 2,
        ),
      ]);

      await tester.pumpWidget(surface());
      await tester.pump();
      expect(player.videoRects, hasLength(1));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(
        player.videoRects.last,
        const PlayerVideoRect(left: 0, top: 0, width: 0, height: 0, scale: 1),
      );
    },
  );
  for (final window in const [Size(1920, 1080), Size(3840, 2160)]) {
    for (final dpr in [1.0, 1.5, 2.0]) {
      testWidgets('accumulated video bounds at $window DPR $dpr', (
        tester,
      ) async {
        tester.view.devicePixelRatio = dpr;
        tester.view.physicalSize = window * dpr;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final player = FakeNativePlayer();
        Widget surface() => MaterialApp(
          builder: LineupCanvas.builder,
          home: Stack(
            children: [
              Positioned(
                left: 40,
                top: 50,
                width: 200,
                height: 100,
                child: Transform.translate(
                  offset: const Offset(12, 8),
                  child: Transform.scale(
                    scale: 1.25,
                    alignment: Alignment.topLeft,
                    child: NativeVideoSurface(player: player),
                  ),
                ),
              ),
            ],
          ),
        );
        await tester.pumpWidget(surface());
        await tester.pump();
        final scale = LineupCanvas.scaleFor(window);
        expect(player.videoRects, [
          PlayerVideoRect(
            left: 52 * scale,
            top: 58 * scale,
            width: 250 * scale,
            height: 125 * scale,
            scale: dpr,
          ),
        ]);
        await tester.pumpWidget(surface());
        await tester.pump();
        expect(player.videoRects, hasLength(1));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(
          player.videoRects.last,
          const PlayerVideoRect(left: 0, top: 0, width: 0, height: 0, scale: 1),
        );
      });
    }
  }
}
