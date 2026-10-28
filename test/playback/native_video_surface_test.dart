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
  testWidgets('replacing the surface transfers bounds without hiding video', (
    tester,
  ) async {
    final player = FakeNativePlayer();
    Widget surface(String key, double width) => MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          height: 100,
          child: NativeVideoSurface(key: ValueKey(key), player: player),
        ),
      ),
    );

    await tester.pumpWidget(surface('player', 400));
    await tester.pumpWidget(surface('guide', 200));
    await tester.pumpWidget(surface('player', 400));

    // Guide/Player replace widgets for the same native output. Disposing the
    // old widget must not destroy that output between its two visible bounds.
    expect(player.videoRects.map((rect) => rect.width), [400, 200, 400]);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(player.videoRects.last.width, 0);
  });

  testWidgets(
    'changing players hides the old output and publishes the new one',
    (tester) async {
      final first = FakeNativePlayer();
      final second = FakeNativePlayer();
      Widget surface(NativePlayer player) =>
          MaterialApp(home: NativeVideoSurface(player: player));

      await tester.pumpWidget(surface(first));
      await tester.pumpWidget(surface(second));
      expect(first.videoRects.last.width, 0);
      expect(second.videoRects.single.width, greaterThan(0));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(second.videoRects.last.width, 0);
    },
  );

  testWidgets('independent players keep their own surface ownership', (
    tester,
  ) async {
    final first = FakeNativePlayer();
    final second = FakeNativePlayer();
    Widget surfaces(bool includeFirst) => MaterialApp(
      home: Row(
        children: [
          if (includeFirst)
            Expanded(
              key: const ValueKey('first'),
              child: NativeVideoSurface(player: first),
            ),
          Expanded(
            key: const ValueKey('second'),
            child: NativeVideoSurface(player: second),
          ),
        ],
      ),
    );

    await tester.pumpWidget(surfaces(true));
    await tester.pumpWidget(surfaces(false));
    expect(first.videoRects.last.width, 0);
    expect(second.videoRects.every((rect) => rect.width > 0), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(second.videoRects.last.width, 0);
  });

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
